import 'package:flutter/material.dart';
import 'package:zero/core/dtext.dart';

abstract final class OtaIconKeys {
  static const String profileAgency = 'profile_agency';
  static const String profileRechargeAgent = 'profile_recharge_agent';
  static const String badgeRechargeAgent = 'badge_recharge_agent';
  static const String badgeAgencyOwner = 'badge_agency_owner';
  static const String badgeAgencyHost = 'badge_agency_host';
  static const String badgeFreeAgent = 'badge_free_agent';
}

class OtaEmojiIcon extends StatelessWidget {
  final String iconKey;
  final String emoji;
  final double size;

  const OtaEmojiIcon({
    super.key,
    required this.iconKey,
    required this.emoji,
    this.size = 24,
  });

  @override
  Widget build(BuildContext context) {
    return DText(
      emoji,
      style: TextStyle(fontSize: size),
    );
  }
}
