import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../../core/supabase_compat.dart';

import '../../../core/utils/server_time_service.dart';
import '../../../core/widgets/ota_icon.dart';
import '../data/agency_models.dart';
import '../../../core/cache/encrypted_image_provider.dart';
import 'package:zero/core/dtext.dart';

// ═══════════════════════════════════════════════════════════════════
//  AgencyBadgeWidget — شارة الوكالة في البروفايل
//  يعرض: اسم الوكالة + درجتها + صورتها + زر للانتقال لصفحة الوكالة
// ═══════════════════════════════════════════════════════════════════
class AgencyBadgeWidget extends StatelessWidget {
  final String userId;
  final VoidCallback? onTap;

  const AgencyBadgeWidget({super.key, required this.userId, this.onTap});

  static const _tierColors = {
    AgencyTier.bronze:   Color(0xFFCD7F32),
    AgencyTier.silver:   Color(0xFFC0C0C0),
    AgencyTier.gold:     Color(0xFFD4AF37),
    AgencyTier.platinum: Color(0xFF6ADBF5),
    AgencyTier.diamond:  Color(0xFFB39DDB),
  };

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _fetchAgency(userId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const SizedBox(height: 28, width: 100,
            child: Center(child: SizedBox(width: 14, height: 14,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFFD4AF37)))));
        }
        final data = snap.data;
        if (data == null) return const SizedBox.shrink();

        final agencyName = data['agency_name'] as String? ?? '—';
        final tier       = AgencyTierX.fromString(data['tier'] as String? ?? 'bronze');
        final photoUrl   = data['photo_url'] as String?;
        final isHOF      = data['is_hall_of_fame'] as bool? ?? false;
        final color      = _tierColors[tier] ?? const Color(0xFFD4AF37);

        return GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withOpacity(0.4)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              // Agency logo
              if (photoUrl != null)
                ClipOval(child: Image(image: EncryptedImageProvider(photoUrl), width: 20, height: 20, fit: BoxFit.cover))
              else
                OtaEmojiIcon(
                  iconKey: OtaIconKeys.badgeAgencyHost,
                  emoji: agencyName.characters.first,
                  size: 20,
                ),
              const SizedBox(width: 6),
              // Name
              Flexible(child: DText(agencyName,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600))),
              if (isHOF) ...[
                const SizedBox(width: 3),
                const DText('🏆', style: TextStyle(fontSize: 10)),
              ],
            ]),
          ),
        );
      },
    );
  }

  static Future<Map<String, dynamic>?> _fetchAgency(String userId) async {
    try {
      final resp = await Supabase.instance.client
          .from('host_agency_members')
          .select('''
            agency_id,
            host_agencies(name, photo_url, tier, is_hall_of_fame)
          ''')
          .eq('user_id', userId)
          .eq('status', 'active')
          .maybeSingle();
      if (resp == null) return null;
      final agency = resp['host_agencies'] as Map<String, dynamic>?;
      if (agency == null) return null;
      return {
        'agency_id':     resp['agency_id'] as String,
        'agency_name':   agency['name'] as String?,
        'tier':          agency['tier'] as String?,
        'photo_url':     agency['photo_url'] as String?,
        'is_hall_of_fame': agency['is_hall_of_fame'] as bool?,
      };
    } catch (e) {
debugPrint('[agency_badge_widget] error: $e');
      return null;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════
//  FreeAgentBadge — شارة "وكيل حر" تُعرض عندما لا يكون في وكالة
// ═══════════════════════════════════════════════════════════════════
class FreeAgentBadge extends StatelessWidget {
  final DateTime freeUntil;

  const FreeAgentBadge({super.key, required this.freeUntil});

  @override
  Widget build(BuildContext context) {
    final daysLeft = freeUntil.difference(ServerTimeService.instance.now()).inDays;
    if (daysLeft <= 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF00E5A0).withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF00E5A0).withOpacity(0.4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        OtaEmojiIcon(iconKey: OtaIconKeys.badgeFreeAgent, emoji: '🦅', size: 18),
        const SizedBox(width: 5),
        DText('وكيل حر ($daysLeft أيام)',
          style: const TextStyle(color: Color(0xFF00E5A0), fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  AgencyStatusBadge — يعرض الشارة المناسبة (وكالة / وكيل حر / لا شيء)
// ═══════════════════════════════════════════════════════════════════
class AgencyStatusBadge extends StatelessWidget {
  final String userId;
  final VoidCallback? onAgencyTap;

  const AgencyStatusBadge({super.key, required this.userId, this.onAgencyTap});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_AgencyStatus>(
      future: _fetchStatus(userId),
      builder: (_, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final status = snap.data!;
        if (status.inAgency) {
          return AgencyBadgeWidget(userId: userId, onTap: onAgencyTap);
        }
        if (status.freeAgentUntil != null) {
          return FreeAgentBadge(freeUntil: status.freeAgentUntil!);
        }
        return const SizedBox.shrink();
      },
    );
  }

  static Future<_AgencyStatus> _fetchStatus(String userId) async {
    final sb = Supabase.instance.client;

    // Check if in active agency
    final memberRow = await sb.from('host_agency_members')
        .select('id')
        .eq('user_id', userId)
        .eq('status', 'active')
        .maybeSingle();

    if (memberRow != null) {
      return _AgencyStatus(inAgency: true);
    }

    // Check if free agent
    final freeRow = await sb.from('agency_free_agents')
        .select('free_until')
        .eq('user_id', userId)
        .maybeSingle();

    if (freeRow != null) {
      final until = DateTime.tryParse(freeRow['free_until'] as String? ?? '');
      if (until != null && until.isAfter(ServerTimeService.instance.now())) {
        return _AgencyStatus(inAgency: false, freeAgentUntil: until);
      }
    }

    return _AgencyStatus(inAgency: false);
  }
}

class _AgencyStatus {
  final bool inAgency;
  final DateTime? freeAgentUntil;
  const _AgencyStatus({required this.inAgency, this.freeAgentUntil});
}
