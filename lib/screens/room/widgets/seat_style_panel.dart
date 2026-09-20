import 'package:flutter/material.dart';
import '../../../config/r.dart';
import '../../../services/dynamic_config_service.dart';

// ═══════════════════════════════════════════════════════════════════
// SeatStylePanel — room_fragment_seat_style.xml
//
// 100% Match with Original Reference:
// • Top decor banner: room_mic_seat_style_top_bg (96dp, fitXY)
// • Top bar: Title "Seat Style" + close button (common_close_ic_2)
// • RadioGroup cards (minHeight 104dp):
//     - Game    → rb_seat_style_game    (room_mic_seat_style_default_ic)
//     - Classic → rb_seat_style_normal  (room_mic_seat_style_default_ic)
//     - VIP     → rb_seat_style_vip     (room_mic_seat_default_vip_2_ic)
//     - Background: room_seat_style_pre (checked) / room_seat_style_nor (unchecked)
// • Subtitle: "Number of seats" (15sp, bold, white)
// • Horizontal list of seat counts:
//     - Frame: room_bg_seat_pre (104×160) + count preview image + label
// • Confirm button: btn_shape_confirm_12_bg (golden gradient, radius 12)
// ═══════════════════════════════════════════════════════════════════

enum SeatStyle { game, classic, vip }

class SeatStylePanel extends StatefulWidget {
  final SeatStyle initialStyle;
  final int initialSeatCount;
  final void Function(SeatStyle style, int count)? onConfirm;
  final VoidCallback? onClose;

  const SeatStylePanel({
    super.key,
    this.initialStyle = SeatStyle.classic,
    this.initialSeatCount = 10,
    this.onConfirm,
    this.onClose,
  });

  @override
  State<SeatStylePanel> createState() => _SeatStylePanelState();
}

class _SeatStylePanelState extends State<SeatStylePanel> {
  late SeatStyle _style;
  late int _count;

  static const _classicCounts = [8, 10, 12, 15, 20];
  static const _vipCounts = [8, 10, 12, 15, 20];
  static const _gameCounts = [10];

  @override
  void initState() {
    super.initState();
    _style = widget.initialStyle;
    _count = widget.initialSeatCount;
  }

  List<int> get _availableCounts {
    switch (_style) {
      case SeatStyle.game:
        return _gameCounts;
      case SeatStyle.classic:
        return _classicCounts;
      case SeatStyle.vip:
        return _vipCounts;
    }
  }

  String _styleImage(SeatStyle style, int count) {
    switch (style) {
      case SeatStyle.classic:
        return R.mipmap('room_bg_classic_seat_$count');
      case SeatStyle.vip:
        return R.mipmap('room_bg_vip_seat_$count');
      case SeatStyle.game:
        return R.mipmap('room_bg_game_seat_10');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    final cfg = DynamicConfigService();

    return Container(
      decoration: BoxDecoration(
        color: cfg.roomSeatPanelBgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Stack(
        children: [
          // ── Top decorative image (room_mic_seat_style_top_bg) ──
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 96,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: R.loadAssetOr(
                cfg.roomSeatPanelTopBg,
                R.roomMicSeatStyleTopBg,
                fit: BoxFit.fill,
              ),
            ),
          ),

          // ── Main content ──
          Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header: Title & Close Icon ──
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Text(
                        isAr ? 'شكل المقاعد' : 'Seat Style',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: widget.onClose ?? () => Navigator.pop(context),
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: R.loadAssetOr(
                            '',
                            R.commonCloseIc2,
                            width: 22,
                            height: 22,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // ── RadioGroup: Game / Classic / VIP ──
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      // Game
                      Expanded(
                        child: _StyleCard(
                          label: isAr ? 'لعبة' : 'Game',
                          iconAsset: cfg.roomSeatGameIcon.isNotEmpty
                              ? cfg.roomSeatGameIcon
                              : R.roomMicSeatStyleDefaultIc,
                          selected: _style == SeatStyle.game,
                          checkedBg: cfg.roomSeatRadioCheckedBg,
                          uncheckedBg: cfg.roomSeatRadioUncheckedBg,
                          onTap: () {
                            setState(() {
                              _style = SeatStyle.game;
                              if (!_availableCounts.contains(_count)) {
                                _count = _availableCounts.first;
                              }
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Classic
                      Expanded(
                        child: _StyleCard(
                          label: isAr ? 'كلاسيكي' : 'Classic',
                          iconAsset: cfg.roomSeatClassicIcon.isNotEmpty
                              ? cfg.roomSeatClassicIcon
                              : R.roomMicSeatStyleDefaultIc,
                          selected: _style == SeatStyle.classic,
                          checkedBg: cfg.roomSeatRadioCheckedBg,
                          uncheckedBg: cfg.roomSeatRadioUncheckedBg,
                          onTap: () {
                            setState(() {
                              _style = SeatStyle.classic;
                              if (!_availableCounts.contains(_count)) {
                                _count = _availableCounts.first;
                              }
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),

                      // VIP
                      Expanded(
                        child: _StyleCard(
                          label: 'VIP',
                          iconAsset: cfg.roomSeatVipIcon.isNotEmpty
                              ? cfg.roomSeatVipIcon
                              : R.roomMicSeatDefaultVip2Ic,
                          selected: _style == SeatStyle.vip,
                          checkedBg: cfg.roomSeatRadioCheckedBg,
                          uncheckedBg: cfg.roomSeatRadioUncheckedBg,
                          onTap: () {
                            setState(() {
                              _style = SeatStyle.vip;
                              if (!_availableCounts.contains(_count)) {
                                _count = _availableCounts.first;
                              }
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ── Subtitle: Number of seats ──
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    isAr ? 'عدد المقاعد' : 'Number of seats',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // ── Horizontal Seat Count Previews ──
                SizedBox(
                  height: 195,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _availableCounts.length,
                    itemBuilder: (_, i) {
                      final count = _availableCounts[i];
                      final selected = _count == count;
                      return GestureDetector(
                        onTap: () => setState(() => _count = count),
                        child: _SeatCountItem(
                          count: count,
                          imagePath: _styleImage(_style, count),
                          frameAsset: cfg.roomSeatPreviewFrame,
                          selected: selected,
                          isAr: isAr,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 20),

                // ── Confirm Button (btn_shape_confirm_12_bg) ──
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: GestureDetector(
                    onTap: () {
                      widget.onConfirm?.call(_style, _count);
                      Navigator.pop(context);
                    },
                    child: Container(
                      width: double.infinity,
                      height: 50,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            cfg.roomSeatConfirmBtnStart,
                            cfg.roomSeatConfirmBtnEnd,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: cfg.roomSeatConfirmBtnEnd.withValues(alpha: 0.35),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        isAr ? 'تأكيد' : 'Confirm',
                        style: TextStyle(
                          fontSize: 15,
                          color: cfg.roomSeatConfirmBtnTextColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
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
}

// ── Square Radio Style Card (matching room_seat_style_group_bg) ──
class _StyleCard extends StatelessWidget {
  final String label;
  final String iconAsset;
  final bool selected;
  final String checkedBg;
  final String uncheckedBg;
  final VoidCallback onTap;

  const _StyleCard({
    required this.label,
    required this.iconAsset,
    required this.selected,
    required this.checkedBg,
    required this.uncheckedBg,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 104,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Background (room_seat_style_pre when selected, room_seat_style_nor when not)
              R.loadAssetOr(
                selected ? checkedBg : uncheckedBg,
                selected ? R.roomSeatStylePre : R.roomSeatStyleNor,
                fit: BoxFit.fill,
              ),

              // Content: Icon on top, Text below
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  R.loadAsset(
                    iconAsset,
                    width: 44,
                    height: 44,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      color: selected ? const Color(0xFFFFE082) : Colors.white,
                      fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Seat Count Item (matching adapter_mic_seat_style_item.xml) ──
class _SeatCountItem extends StatelessWidget {
  final int count;
  final String imagePath;
  final String frameAsset;
  final bool selected;
  final bool isAr;

  const _SeatCountItem({
    required this.count,
    required this.imagePath,
    required this.frameAsset,
    required this.selected,
    required this.isAr,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 104,
      margin: const EdgeInsets.only(right: 12),
      child: Column(
        children: [
          // Frame + Inner preview image (104 × 160)
          Container(
            width: 104,
            height: 160,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? const Color(0xFFFFD19C) : Colors.transparent,
                width: 2,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: const Color(0xFFFFD19C).withValues(alpha: 0.3),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Outer frame: room_bg_seat_pre
                  R.loadAssetOr(
                    frameAsset,
                    R.roomBgSeatPre,
                    fit: BoxFit.fill,
                  ),

                  // Inner style image (iv_img) with 12dp round corners and 5dp margin
                  Padding(
                    padding: const EdgeInsets.all(5),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.asset(
                        imagePath,
                        fit: BoxFit.fill,
                        errorBuilder: (_, __, ___) => const SizedBox(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),

          // Count text below (tv_mic_num)
          Text(
            isAr ? '$count مقاعد' : '$count seats',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: selected ? const Color(0xFFFFE082) : Colors.white,
              fontWeight: selected ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

