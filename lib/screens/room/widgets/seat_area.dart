import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../config/r.dart';
import '../../../config/app_colors.dart';
import '../../../services/dynamic_config_service.dart';
import '../models/seat_model.dart';
import 'svga_frame.dart';

// ═══════════════════════════════════════════════════════════════════
// SeatArea — fragment_mic_seat.xml
//   seat 0 (owner) → adapter_mic_owner_item.xml  مركزي
//   seats 1-19     → adapter_mic_normal_item.xml  5 في كل صف
// ═══════════════════════════════════════════════════════════════════

Widget _loadAvatar(String? avatar, double size) {
  if (avatar == null || avatar.isEmpty) return _emptyCircle(size);
  if (avatar.startsWith('http://') || avatar.startsWith('https://')) {
    return Image(
      image: R.cachedImage(avatar),
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _emptyCircle(size),
    );
  }
  return Image.asset(
    avatar,
    width: size,
    height: size,
    fit: BoxFit.cover,
    errorBuilder: (_, __, ___) => _emptyCircle(size),
  );
}

Widget _emptyCircle(double s) => Container(
  width: s,
  height: s,
  decoration: const BoxDecoration(
    shape: BoxShape.circle,
    color: Color(0x1AFFFFFF),
  ),
  child: Icon(Icons.person, size: s * 0.45, color: Colors.white38),
);

class SeatArea extends StatelessWidget {
  final List<SeatModel> seats;
  final void Function(int index) onSeatTap;
  final void Function()? onCharmTap;
  final bool showCharmValues;
  final Map<int, String>? seatEmojis;
  final Set<String>? moderators;
  final String? hostUid;
  final SeatStyle seatStyle;

  const SeatArea({
    super.key,
    required this.seats,
    required this.onSeatTap,
    this.onCharmTap,
    this.showCharmValues = true,
    this.seatEmojis,
    this.moderators,
    this.hostUid,
    this.seatStyle = SeatStyle.classic,
  });

  @override
  Widget build(BuildContext context) {
    if (seatStyle == SeatStyle.circle) {
      return _buildGameLayout(context);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: _buildGrid(),
    );
  }

  double _getAngleForIndex(int idx) {
    switch (idx) {
      case 2: return -90 * math.pi / 180;
      case 3: return -50 * math.pi / 180;
      case 4: return -10 * math.pi / 180;
      case 5: return 30 * math.pi / 180;
      case 6: return 70 * math.pi / 180;
      case 7: return 110 * math.pi / 180;
      case 8: return 150 * math.pi / 180;
      case 9: return 190 * math.pi / 180;
      case 1: return 230 * math.pi / 180;
      default: return 0.0;
    }
  }

  Widget _buildGameLayout(BuildContext context) {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    final sw = MediaQuery.of(context).size.width;
    final double layoutWidth = sw;
    const double layoutHeight = 420.0;
    final double centerX = layoutWidth / 2;
    final double centerY = layoutHeight / 2;
    const double radius = 140.0;

    return Center(
      child: Container(
        width: layoutWidth,
        height: layoutHeight,
        margin: const EdgeInsets.symmetric(vertical: 10),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Seat 0 (Captain) in the center
            if (seats.isNotEmpty)
              Positioned(
                left: centerX - 38,
                top: centerY - 48,
                child: _buildCircularSeatItem(0, true),
              ),
            // Seats 1 to 9 arranged in a circle
            for (int i = 1; i <= 9; i++)
              if (i < seats.length)
                () {
                  final angle = _getAngleForIndex(i);
                  final dx = radius * math.cos(angle);
                  final dy = radius * math.sin(angle);
                  // Mirror horizontally in Arabic (RTL)
                  final x = isAr ? (centerX - dx) : (centerX + dx);
                  final y = centerY + dy;
                  return Positioned(
                    left: x - 38,
                    top: y - 48,
                    child: _buildCircularSeatItem(i, false),
                  );
                }(),
          ],
        ),
      ),
    );
  }

  Widget _buildCircularSeatItem(int idx, bool isCaptain) {
    return GestureDetector(
      onTap: () => onSeatTap(idx),
      child: Transform.scale(
        scale: 1.2,
        child: _NormalSeat(
          seat: seats[idx],
          emoji: seatEmojis?[idx],
          isModerator: seats[idx].user != null
              ? moderators?.contains(seats[idx].user!.id) ?? false
              : false,
          seatStyle: seatStyle,
          isCaptain: isCaptain,
          showCharmValues: showCharmValues,
          onCharmTap: onCharmTap,
        ),
      ),
    );
  }
  Widget _buildGrid() {
    const seatsPerRow = 5;
    final items = seats;
    final rows = <Widget>[];

    for (int i = 0; i < items.length; i += seatsPerRow) {
      final end = math.min(i + seatsPerRow, items.length);
      final rowItems = items.sublist(i, end);

      rows.add(
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (int j = 0; j < rowItems.length; j++)
              Expanded(
                child: Center(
                  child: GestureDetector(
                    onTap: () => onSeatTap(i + j),
                    child: _NormalSeat(
                      seat: rowItems[j],
                      emoji: seatEmojis?[i + j],
                      isModerator: rowItems[j].user != null
                          ? moderators?.contains(rowItems[j].user!.id) ?? false
                          : false,
                      seatStyle: seatStyle,
                      isCaptain: false,
                      showCharmValues: showCharmValues,
                      onCharmTap: onCharmTap,
                    ),
                  ),
                ),
              ),
            for (int k = rowItems.length; k < seatsPerRow; k++)
              const Expanded(child: SizedBox()),
          ],
        ),
      );

      if (end < items.length) rows.add(const SizedBox(height: 6));
    }

    return Column(mainAxisSize: MainAxisSize.min, children: rows);
  }
}

class _NormalSeat extends StatelessWidget {
  final SeatModel seat;
  final String? emoji;
  final bool isModerator;
  final SeatStyle seatStyle;
  final bool isCaptain;
  final bool showCharmValues;
  final void Function()? onCharmTap;

  const _NormalSeat({
    required this.seat,
    this.emoji,
    this.isModerator = false,
    this.seatStyle = SeatStyle.classic,
    this.isCaptain = false,
    this.showCharmValues = true,
    this.onCharmTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasUser = seat.user != null;
    final user = seat.user;
    final name = user?.name ?? '';
    final charm = user?.charm;
    final avatar = user?.avatar;
    final hasFrame = seat.hasFrame;
    final frameAsset = seat.frameAsset;

    Widget child = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 76,
          height: 88,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                top: 6,
                left: 6,
                child: _buildAvatarPart(hasUser, avatar, hasFrame, frameAsset),
              ),
              if (emoji != null && emoji!.isNotEmpty && hasUser)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Center(
                      child: emoji!.startsWith('http')
                          ? Image.network(emoji!, width: 64, height: 64, fit: BoxFit.contain)
                          : Text(
                              emoji!,
                              style: const TextStyle(fontSize: 48),
                            ),
                    ),
                  ),
                ),
              if (!hasUser && seat.isLocked)
                Positioned(
                  bottom: 2,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: R.image(
                      R.roomMicSeatLockIc,
                      width: 14,
                      height: 14,
                    ),
                  ),
                ),
              if (hasUser && seat.isMuted)
                Positioned(
                  top: 34,
                  left: 36,
                  child: R.image(
                    R.roomMicSeatMuteIc,
                    width: 16,
                    height: 16,
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isModerator)
                Container(
                  margin: const EdgeInsets.only(right: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2196F3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: const Text(
                    'M',
                    style: TextStyle(fontSize: 7, color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              SizedBox(
                width: isModerator ? 48 : 56,
                child: Text(
                  hasUser
                      ? name
                      : (seatStyle == SeatStyle.circle
                          ? (isCaptain ? 'Captain' : '${seat.index}')
                          : (isCaptain ? 'Captain' : '${seat.index + 1}')),
                  style: const TextStyle(fontSize: 11, color: Colors.white),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
        if (hasUser && charm != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: GestureDetector(
              onTap: onCharmTap,
              child: Container(
                padding: const EdgeInsets.fromLTRB(4, 1, 4, 1),
                decoration: BoxDecoration(
                  color: const Color(0x33000000),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    R.image(R.roomMicCharmMaleIc, width: 9, height: 9),
                    if (showCharmValues) ...[
                      const SizedBox(width: 1),
                      Text(
                        _formatCharm(charm),
                        style: const TextStyle(fontSize: 9, color: Colors.white),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );

    if (isCaptain) {
      child = Transform.scale(
        scale: 1.15,
        child: child,
      );
    }
    return child;
  }

  String _formatCharm(String charmStr) {
    final value = int.tryParse(charmStr.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '')}m';
    } else if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '')}k';
    }
    return charmStr;
  }

  Widget _buildAvatarPart(bool hasUser, String? avatar, bool hasFrame, String? frameAsset) {
    const double size = 52.0;
    const double borderSize = 64.0;

    if (!hasUser) {
      final cfg = DynamicConfigService.instance;
      if (seatStyle == SeatStyle.circle) {
        final circleDefault = cfg.roomSeatDefaultCircle.isNotEmpty ? cfg.roomSeatDefaultCircle : R.roomMicSeatDefaultCircle;
        final circleLock = cfg.roomSeatLockCircle.isNotEmpty ? cfg.roomSeatLockCircle : R.roomMicSeatLockCircle;
        return Center(
          child: SizedBox(
            width: size,
            height: size,
            child: seat.isLocked
                ? R.loadAsset(circleLock, fit: BoxFit.cover)
                : R.loadAsset(circleDefault, fit: BoxFit.cover),
          ),
        );
      }

      String emptyIcon = cfg.roomSeatDefaultClassic.isNotEmpty ? cfg.roomSeatDefaultClassic : R.roomMicSeatDefaultIc;
      String lockIcon = cfg.roomSeatLockClassic.isNotEmpty ? cfg.roomSeatLockClassic : R.roomMicSeatLockIc;

      if (seatStyle == SeatStyle.heart) {
        emptyIcon = cfg.roomSeatDefaultVip.isNotEmpty ? cfg.roomSeatDefaultVip : R.mipmap('room_mic_seat_default_vip_2_ic');
        lockIcon = cfg.roomSeatLockVip.isNotEmpty ? cfg.roomSeatLockVip : R.roomMicSeatLockIc;
      }
      return Center(
        child: SizedBox(
          width: borderSize,
          height: borderSize,
          child: Center(
            child: SizedBox(
              width: size,
              height: size,
              child: seat.isLocked
                  ? R.loadAsset(lockIcon, fit: BoxFit.cover)
                  : R.loadAsset(
                      emptyIcon,
                      fit: BoxFit.cover,
                    ),
            ),
          ),
        ),
      );
    }

    final avatarWidget = ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: avatar != null ? _loadAvatar(avatar, size) : _emptyCircle(size),
      ),
    );

    if (hasFrame && frameAsset != null) {
      return Stack(
        alignment: Alignment.center,
        children: [
          avatarWidget,
          IgnorePointer(
            child: SvgaFrame(svgaPath: frameAsset, size: borderSize),
          ),
        ],
      );
    }

    if (seatStyle == SeatStyle.circle) {
      // Game style: thick metallic silver ring
      return Container(
        width: borderSize,
        height: borderSize,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [
              Color(0xFFFFFFFF),
              Color(0xFFBDC3C7),
              Color(0xFF7F8C8D),
              Color(0xFFECEFF1),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        alignment: Alignment.center,
        child: ClipOval(
          child: SizedBox(
            width: borderSize - 8.0,
            height: borderSize - 8.0,
            child: avatarWidget,
          ),
        ),
      );
    } else if (seatStyle == SeatStyle.heart) {
      // VIP style: thick metallic gold ring
      return Container(
        width: borderSize,
        height: borderSize,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [
              Color(0xFFFFF275),
              Color(0xFFD4AF37),
              Color(0xFF8C6200),
              Color(0xFFFFF9C4),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        alignment: Alignment.center,
        child: ClipOval(
          child: SizedBox(
            width: borderSize - 8.0,
            height: borderSize - 8.0,
            child: avatarWidget,
          ),
        ),
      );
    }

    // Classic style: thin gold border (original)
    return SizedBox(
      width: borderSize,
      height: borderSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          avatarWidget,
          Container(
            width: borderSize,
            height: borderSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.goldLight.withValues(alpha: 0.45),
                width: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
