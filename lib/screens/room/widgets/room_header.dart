import 'package:flutter/material.dart';
import '../../../config/r.dart';
import '../../../config/app_colors.dart';
import '../../../services/dynamic_config_service.dart';

class RoomHeader extends StatelessWidget {
  final String? roomName;
  final String? roomId;
  final String? hostAvatar;
  final bool isLocked;
  final String? hotValue;
  final String? gameDesc;
  final String? onlineCount;
  final List<String> onlineAvatars;
  final bool isFollowed;
  final VoidCallback onExit;
  final VoidCallback? onMinimize;
  final VoidCallback? onRank;
  final VoidCallback? onInfoTap;
  final VoidCallback? onOnlineTap;
  final VoidCallback? onGameTap;
  final VoidCallback? onFollow;

  const RoomHeader({
    super.key,
    this.roomName,
    this.roomId,
    this.hostAvatar,
    this.isLocked = false,
    this.hotValue,
    this.gameDesc,
    this.onlineCount,
    this.onlineAvatars = const [],
    this.isFollowed = false,
    required this.onExit,
    this.onMinimize,
    this.onRank,
    this.onInfoTap,
    this.onOnlineTap,
    this.onGameTap,
    this.onFollow,
  });

  @override
  Widget build(BuildContext context) {
    final statusH = MediaQuery.of(context).padding.top;
    final sw = MediaQuery.of(context).size.width;
    final isAr = Localizations.localeOf(context).languageCode == 'ar';

    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: statusH),
          Container(
            height: 50,
            child: Stack(
              children: [
                Positioned(
                  left: isAr ? null : 0,
                  right: isAr ? 0 : null,
                  top: 0,
                  bottom: 0,
                  width: sw * 0.45,
                  child: GestureDetector(
                    onTap: onInfoTap,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(isAr ? 0 : 14, 0, isAr ? 14 : 0, 5),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _buildRoomAvatar(),
                          const SizedBox(width: 5),
                          _buildRoomInfoText(context, isAr),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: isAr ? 12 : null,
                  right: isAr ? null : 12,
                  top: 0,
                  bottom: 0,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _buildOnlineButton(),
                      const SizedBox(width: 8),
                      _buildRankButton(),
                      const SizedBox(width: 8),
                      _buildMinimizeButton(),
                      const SizedBox(width: 8),
                      _buildExitButton(),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Game Description panel below header (matches cl_game_them in fragment_room_info.xml)
          Container(
            height: 32,
            color: DynamicConfigService.instance.roomGameBarBgColor,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: onGameTap,
                    behavior: HitTestBehavior.opaque,
                    child: Row(
                      children: [
                        const SizedBox(width: 5),
                        R.loadAsset(
                          DynamicConfigService.instance.roomGameIcon.isNotEmpty
                              ? DynamicConfigService.instance.roomGameIcon
                              : R.roomGameIc,
                          width: 24,
                          height: 24,
                          fit: BoxFit.cover,
                        ),
                        const SizedBox(width: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white12,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'GAME',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: DynamicConfigService.instance.roomGameBarTextColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            (gameDesc != null && gameDesc!.isNotEmpty)
                                ? gameDesc!
                                : (isAr ? 'ألعاب الغرفة التفاعلية 🎮' : 'Room Games 🎮'),
                            style: TextStyle(
                              fontSize: 10,
                              color: DynamicConfigService.instance.roomGameBarDescColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: onOnlineTap,
                    child: Container(
                      height: 24,
                      padding: const EdgeInsets.only(left: 4),
                      decoration: BoxDecoration(
                        image: DecorationImage(
                          image: (DynamicConfigService.instance.roomOnlineCapsuleBg.isNotEmpty)
                              ? R.cachedImage(DynamicConfigService.instance.roomOnlineCapsuleBg)
                              : AssetImage(R.roomOnlineInfoBg) as ImageProvider,
                          fit: BoxFit.fill,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _OverlapAvatars(
                            avatars: onlineAvatars.isEmpty
                                ? [R.avaBoy, R.avaGirl]
                                : onlineAvatars,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            onlineCount ?? '0',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 2),
                          R.image(
                            R.nextWhiteIc,
                            width: 10,
                            height: 10,
                          ),
                          const SizedBox(width: 6),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRoomAvatar() {
    final avatar = (hostAvatar != null && hostAvatar!.isNotEmpty) ? hostAvatar! : R.avaBoy;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: R.loadImage(
        avatar,
        width: 40,
        height: 40,
        fit: BoxFit.cover,
      ),
    );
  }

  Widget _buildRoomInfoText(BuildContext context, bool isAr) {
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            roomName ?? 'Room',
            style: TextStyle(
              fontSize: 13,
              color: DynamicConfigService.instance.roomHeaderTextColor,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'ID: ${roomId ?? '------'}',
                style: const TextStyle(fontSize: 10, color: Color(0xB2FFFFFF)),
              ),
              if (isLocked) ...[
                const SizedBox(width: 2),
                R.image(R.roomLockStateIc, width: 12, height: 12),
              ],
              const SizedBox(width: 2),
              R.image(R.roomHotLogoIc, width: 10, height: 10),
              const SizedBox(width: 2),
              Text(
                hotValue ?? '0',
                style: const TextStyle(fontSize: 10, color: Color(0xB2FFFFFF)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExitButton() {
    final exitIcon = DynamicConfigService.instance.roomExitIcon.isNotEmpty
        ? DynamicConfigService.instance.roomExitIcon
        : R.roomExitIc;
    return GestureDetector(
      onTap: onExit,
      child: Center(
        child: R.loadAsset(
          exitIcon,
          width: 24,
          height: 24,
        ),
      ),
    );
  }

  Widget _buildMinimizeButton() {
    return GestureDetector(
      onTap: onMinimize,
      child: Container(
        width: 28,
        height: 28,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black26,
        ),
        child: const Icon(
          Icons.close_fullscreen,
          color: Colors.white,
          size: 16,
        ),
      ),
    );
  }

  Widget _buildRankButton() {
    return GestureDetector(
      onTap: onRank,
      child: Container(
        width: 28,
        height: 28,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black26,
        ),
        child: const Icon(
          Icons.emoji_events,
          color: Color(0xFFFFD54F),
          size: 18,
        ),
      ),
    );
  }

  Widget _buildOnlineButton() {
    return GestureDetector(
      onTap: onOnlineTap,
      behavior: HitTestBehavior.opaque,
      child: Image.asset(
        'assets/images/room_online_robot_ic.webp',
        width: 32,
        height: 32,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Icon(
          Icons.people_alt_rounded,
          color: Color(0xFFFFD54F),
          size: 24,
        ),
      ),
    );
  }
}

class _OverlapAvatars extends StatelessWidget {
  final List<String> avatars;
  const _OverlapAvatars({required this.avatars});

  @override
  Widget build(BuildContext context) {
    const double size = 16;
    const double step = 10;
    final count = avatars.length.clamp(0, 3);
    return SizedBox(
      width: size + (count - 1) * step,
      height: size,
      child: Stack(
        children: [
          for (int i = 0; i < count; i++)
            Positioned(
              left: i * step,
              child: ClipOval(
                child: Image.asset(
                  avatars[i],
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: size,
                    height: size,
                    decoration: const BoxDecoration(
                      color: AppColors.cardBg,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
